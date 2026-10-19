#!/usr/bin/env bash
# Usage: ./build.sh <target> [tool] [args]
#   check | test            all packages, all tools
#   native [tool]           build/<tool>
#   run [tool] [file]       build and run natively
#   web [tool]              build/web/<tool>/
#   serve [tool] [port]     web + http.server (default port 8000)
# Tools live in apps/<tool>/ (default: palette_editor).
set -euo pipefail
cd "$(dirname "$0")"

target="${1:-test}"
[ $# -gt 0 ] && shift
tool=palette_editor
if [ $# -gt 0 ] && [ -d "apps/$1" ]; then
	tool="$1"
	shift
fi
coll="-collection:app=apps/$tool"

build_web() {
	local out="build/web/$tool"
	mkdir -p "$out"
	odin build frontends/web -target:js_wasm32 "$coll" -out:"$out/app.wasm" -o:speed
	cp "$(odin root)/core/sys/wasm/js/odin.js" input_map.json "$out/"
	sed -e "s/@TITLE@/$(cat "apps/$tool/title.txt")/" -e "s/@TOOL@/$tool/" frontends/web/index.html > "$out/index.html"
}

case "$target" in
	check)
		for pkg in common palette_editor gamepad_tester; do odin check "$pkg" -no-entry-point; done
		for t in apps/*/; do
			t="$(basename "$t")"
			odin check frontends/sdl2 "-collection:app=apps/$t"
			odin check frontends/web -target:js_wasm32 "-collection:app=apps/$t"
		done ;;
	test)
		for pkg in common palette_editor gamepad_tester; do odin test "$pkg"; done ;;
	native) mkdir -p build && odin build frontends/sdl2 "$coll" -out:"build/$tool" ;;
	run)    "$0" native "$tool" && "./build/$tool" "$@" ;;
	web)    build_web ;;
	serve)  build_web && python3 -m http.server -d "build/web/$tool" "${1:-8000}" ;;
	*) echo "unknown target: $target (expected check, test, native, run, web or serve)" >&2; exit 2 ;;
esac
