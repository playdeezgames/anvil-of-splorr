#!/usr/bin/env bash
# Usage: ./build.sh [check|test|native|run [file.pal]]
# The web target is added when that frontend exists.
set -euo pipefail
cd "$(dirname "$0")"

target="${1:-test}"
[ $# -gt 0 ] && shift

case "$target" in
	check)  odin check common -no-entry-point && odin check palette_editor -no-entry-point \
	          && odin check frontends/sdl2 ;;
	test)   odin test common && odin test palette_editor ;;
	native) mkdir -p build && odin build frontends/sdl2 -out:build/palette_editor ;;
	run)    "$0" native && ./build/palette_editor "$@" ;;
	*) echo "unknown target: $target (expected check, test, native or run)" >&2; exit 2 ;;
esac
