#!/usr/bin/env bash
# Usage: ./build.sh <target> [tool] [args]
#   check | test            all packages, all tools
#   native [tool]           build/<tool>
#   run [tool] [file]       build and run natively
#   web [tool]              build/web/<tool>/
#   serve [tool] [port]     web + http.server (default port 8000)
# Builds select what to include with apps/<name>/: "suite" (default) is the main menu plus every
# editor; "palette_editor", "image_editor", "tileset_editor", "world_editor", "glyph_editor", "font_editor" and "gamepad_tester" build a single tool on its own.
set -euo pipefail
cd "$(dirname "$0")"

target="${1:-test}"
[ $# -gt 0 ] && shift
tool=suite
if [ $# -gt 0 ] && [ -d "apps/$1" ]; then
	tool="$1"
	shift
fi
coll="-collection:app=apps/$tool"

build_web() {
	local out="build/web/$tool"
	mkdir -p "$out"
	odin build frontends/web -target:js_wasm32 "$coll" -out:"$out/app.wasm" -o:"${WEB_OPT:-minimal}"
	cp "$(odin root)/core/sys/wasm/js/odin.js" "$out/"
	# A link, not a copy: the repo-root input_map.json is the one file to edit, and a rebuild must
	# never overwrite edits made through the served path.
	ln -sfn ../../../input_map.json "$out/input_map.json"
	sed -e "s/@TITLE@/$(cat "apps/$tool/title.txt")/" frontends/web/index.html > "$out/index.html"
}

case "$target" in
	check)
		for pkg in common palette_editor image_editor tileset_editor map_editor terrain_editor sprite_editor world_editor glyph_editor font_editor gamepad_tester launcher; do odin check "$pkg" -no-entry-point; done
		for t in apps/*/; do
			t="$(basename "$t")"
			odin check frontends/sdl2 "-collection:app=apps/$t"
			odin check frontends/web -target:js_wasm32 "-collection:app=apps/$t"
		done ;;
	test)
		for pkg in common palette_editor image_editor tileset_editor map_editor terrain_editor sprite_editor world_editor glyph_editor font_editor gamepad_tester launcher; do odin test "$pkg"; done ;;
	native) mkdir -p build && odin build frontends/sdl2 "$coll" -out:"build/$tool" ;;
	run)    "$0" native "$tool" && "./build/$tool" "$@" ;;
	web)    build_web ;;
	serve)  build_web && python3 -m http.server -d "build/web/$tool" "${1:-8000}" ;;
	*) echo "unknown target: $target (expected check, test, native, run web or serve)" >&2; exit 2 ;;
esac
