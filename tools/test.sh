#!/usr/bin/env bash
# Import the project (so fresh checkouts have their class_names), then run all GUT tests.
# Exits with GUT's status.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
godot --headless --import --path . || exit $?
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit "$@"
