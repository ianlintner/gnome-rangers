#!/usr/bin/env bash
# Install the Godot build this repository is pinned to.
#
# Reads tools/godot-version.txt (e.g. "4.7.2-stable"), downloads the official
# linux x86_64 build from github.com/godotengine/godot-builds, verifies it
# against that release's published SHA512-SUMS.txt, and installs it to
# ~/.local/bin/godot. Idempotent: when the pinned version is already installed
# it just prints the version and exits.
#
# Usage: tools/get_godot.sh [--force] [--install-dir DIR]
#   GODOT_INSTALL_DIR  override the install directory (default ~/.local/bin)
#   GODOT_CACHE_DIR    override the download cache (default ~/.cache/...)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_FILE="$REPO_ROOT/tools/godot-version.txt"
INSTALL_DIR="${GODOT_INSTALL_DIR:-$HOME/.local/bin}"
CACHE_DIR="${GODOT_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/gnome-rangers/godot}"
FORCE=0

while [ $# -gt 0 ]; do
	case "$1" in
	--force) FORCE=1 ;;
	--install-dir)
		INSTALL_DIR="$2"
		shift
		;;
	-h | --help)
		sed -n '2,13p' "$0"
		exit 0
		;;
	*)
		echo "get_godot.sh: unknown argument: $1" >&2
		exit 2
		;;
	esac
	shift
done

if [ ! -f "$VERSION_FILE" ]; then
	echo "get_godot.sh: missing $VERSION_FILE" >&2
	exit 1
fi

TAG="$(tr -d '[:space:]' <"$VERSION_FILE")"
NUM="${TAG%-*}"
CHANNEL="${TAG##*-}"
PREFIX="$NUM.$CHANNEL"
ASSET="Godot_v${TAG}_linux.x86_64.zip"
BASE_URL="https://github.com/godotengine/godot-builds/releases/download/${TAG}"

arch="$(uname -m)"
if [ "$arch" != "x86_64" ]; then
	echo "get_godot.sh: only linux x86_64 builds are pinned here (host is $arch)" >&2
	exit 1
fi

installed_version() {
	if [ -x "$INSTALL_DIR/godot" ]; then
		"$INSTALL_DIR/godot" --version 2>/dev/null || true
	fi
}

current="$(installed_version)"
if [ "$FORCE" -eq 0 ] && [[ "$current" == "$PREFIX"* ]]; then
	echo "godot $current already installed at $INSTALL_DIR/godot (pinned $TAG)"
	exit 0
fi

echo "get_godot.sh: installing Godot $TAG into $INSTALL_DIR"
mkdir -p "$CACHE_DIR" "$INSTALL_DIR"

zip_path="$CACHE_DIR/$ASSET"
sums_path="$CACHE_DIR/SHA512-SUMS.txt"

download() {
	local url="$1" dest="$2"
	if [ -s "$dest" ] && [ "$FORCE" -eq 0 ]; then
		return 0
	fi
	echo "get_godot.sh: downloading $url"
	curl --fail --location --silent --show-error --retry 3 --output "$dest.part" "$url"
	mv "$dest.part" "$dest"
}

download "$BASE_URL/$ASSET" "$zip_path"
download "$BASE_URL/SHA512-SUMS.txt" "$sums_path"

expected="$(grep -E "[[:space:]]${ASSET}\$" "$sums_path" | awk '{print $1}')"
if [ -z "$expected" ]; then
	echo "get_godot.sh: $ASSET not listed in SHA512-SUMS.txt" >&2
	exit 1
fi

actual="$(sha512sum "$zip_path" | awk '{print $1}')"
if [ "$actual" != "$expected" ]; then
	echo "get_godot.sh: checksum mismatch for $ASSET" >&2
	echo "  expected $expected" >&2
	echo "  actual   $actual" >&2
	exit 1
fi
echo "get_godot.sh: SHA512 verified for $ASSET"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
unzip -o -q "$zip_path" -d "$tmp_dir"

binary="$tmp_dir/Godot_v${TAG}_linux.x86_64"
if [ ! -f "$binary" ]; then
	echo "get_godot.sh: $ASSET did not contain the expected binary" >&2
	exit 1
fi

install -m 0755 "$binary" "$INSTALL_DIR/godot"
echo "get_godot.sh: installed $INSTALL_DIR/godot"
"$INSTALL_DIR/godot" --version
