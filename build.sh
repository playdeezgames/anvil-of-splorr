#!/usr/bin/env bash
# Usage: ./build.sh [check|test|native|run [file.pal]|web|serve [port]]
set -euo pipefail
cd "$(dirname "$0")"

target="${1:-test}"
[ $# -gt 0 ] && shift

case "$target" in
	check)  odin check common -no-entry-point && odin check palette_editor -no-entry-point \
	          && odin check frontends/sdl2 \
	          && odin check frontends/web -target:js_wasm32 ;;
	test)   odin test common && odin test palette_editor && odin test frontends/web ;;
	native) mkdir -p build && odin build frontends/sdl2 -out:build/palette_editor ;;
	web)    mkdir -p build/web \
	          && odin build frontends/web -target:js_wasm32 -out:build/web/palette_editor.wasm -o:speed \
	          && cp "$(odin root)/core/sys/wasm/js/odin.js" frontends/web/index.html build/web/ ;;
	serve)  "$0" web && python3 -m http.server -d build/web "${1:-8000}" ;;
	run)    "$0" native && ./build/palette_editor "$@" ;;
	*) echo "unknown target: $target (expected check, test, native, run, web or serve)" >&2; exit 2 ;;
esac
