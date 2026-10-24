#!/usr/bin/env bash
# Usage: ./build.sh <target> [tool] [args]
#   check | test            all packages, all tools
#   native [tool]           build/<tool>
#   mcp                     build/anvil_mcp, the MCP server (see MCP.md)
#   install-mcp             a stable copy in ~/.local/bin/anvil_mcp for other sessions
#   run [tool] [file]       build and run natively
#   web [tool]              build/web/<tool>/
#   (APP_DIR=<dir with app.odin> [APP_NAME=] [OUT_DIR=] before native|web|run|serve builds a game's own app: see GAMES.md)
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
anvil_dir="$PWD"
coll="-collection:app=apps/$tool"
title_file="apps/$tool/title.txt"
input_map="$anvil_dir/input_map.json"
tags_file="$anvil_dir/game_tags.json"
web_out="build/web/$tool"
native_out="build/$tool"

# A game's own app: APP_DIR is the folder holding its app.odin (package app, `make_tool`), anywhere on
# disk. The frontends build around it exactly as for apps/<name>. Optional beside it (in APP_DIR or its
# parent): title.txt, input_map.json (the web page's key and button bindings, instead of the Anvil's)
# and game_tags.json. APP_NAME names the output (default: the folder above APP_DIR); OUT_DIR is where
# the output goes (default build/). The game imports the Anvil's packages as "anvil:common" and
# "anvil:anvil_runtime": every build passes -collection:anvil=<this repo>. See GAMES.md.
if [ -n "${APP_DIR:-}" ]; then
	app_abs="$(cd "$APP_DIR" && pwd)"
	[ -f "$app_abs/app.odin" ] || { echo "APP_DIR $APP_DIR has no app.odin" >&2; exit 2; }
	tool="${APP_NAME:-$(basename "$(dirname "$app_abs")")}"
	# the app collection's root holds the package as "app", whatever the folder is called
	ext="$anvil_dir/build/ext/$tool"
	mkdir -p "$ext" && ln -sfn "$app_abs" "$ext/app"
	coll="-collection:app=$ext"
	parent="$(dirname "$app_abs")"
	first_file() { for f in "$@"; do if [ -f "$f" ]; then echo "$f"; return; fi; done; }
	title_file="$(first_file "$app_abs/title.txt" "$parent/title.txt")"
	if [ -z "$title_file" ]; then echo "$tool" > "$ext/title.txt"; title_file="$ext/title.txt"; fi
	input_map="$(first_file "$app_abs/input_map.json" "$parent/input_map.json")"
	[ -n "$input_map" ] || input_map="$anvil_dir/input_map.json"
	tags_file="$(first_file "$app_abs/game_tags.json" "$parent/game_tags.json")" # (none: the Anvil's own list is not the game's)
	web_out="${OUT_DIR:-build}/web/$tool"
	native_out="${OUT_DIR:-build}/$tool"
elif [ -n "${OUT_DIR:-}" ]; then
	web_out="$OUT_DIR/web/$tool"
	native_out="$OUT_DIR/$tool"
fi
coll="$coll -collection:anvil=$anvil_dir"

build_web() {
	local out="$web_out"
	mkdir -p "$out"
	odin build frontends/web -target:js_wasm32 $coll -out:"$out/app.wasm" -o:"${WEB_OPT:-minimal}" -define:FILE_CAP_MIB="${WEB_FILE_MIB:-4}"
	cp "$(odin root)/core/sys/wasm/js/odin.js" "$out/"
	# A link, not a copy: the input_map.json (the Anvil's, or the game's own) is the one file to edit,
	# and a rebuild must never overwrite edits made through the served path.
	ln -sfn "$(realpath "$input_map")" "$out/input_map.json"
	# game_tags.json (the tags a game needs), if there is one, is served next to the page for the world
	# editor; a game's own copy can also be dropped into the output folder or chosen with the page's
	# "Open file" button.
	if [ -e "$tags_file" ]; then ln -sfn "$(realpath "$tags_file")" "$out/game_tags.json"; fi
	# WEB_FETCH="world.json" makes the page fetch those files from beside it and give them to the tool at
	# start (a shipped game's world); WEB_FILE_MIB=<n> raises the file buffer from its default 4 MiB.
	fetch_meta=""
	if [ -n "${WEB_FETCH:-}" ]; then fetch_meta="<meta name=\"anvil-fetch\" content=\"${WEB_FETCH}\">"; fi
	sed -e "s/@TITLE@/$(cat "$title_file")/" -e "s|@FETCH@|$fetch_meta|" frontends/web/index.html > "$out/index.html"
}

case "$target" in
	check)
		for pkg in common palette_editor image_editor tileset_editor map_editor terrain_editor sprite_editor character_type_editor character_editor feature_type_editor feature_editor item_type_editor inventory_editor controls_editor world_editor glyph_editor font_editor gamepad_tester launcher anvil_runtime mcp_server; do odin check "$pkg" -no-entry-point; done
		odin check anvil_runtime -no-entry-point -target:js_wasm32
		odin check anvil_mcp
		for t in apps/*/; do
			t="$(basename "$t")"
			odin check frontends/sdl2 "-collection:app=apps/$t"
			odin check frontends/web -target:js_wasm32 "-collection:app=apps/$t"
		done
		# The recipe for a game's own app (GAMES.md) must not rot: build a tiny external one both ways.
		odin test testdata/external_app/app -collection:anvil="$PWD"
		APP_DIR=testdata/external_app/app APP_NAME=external_check OUT_DIR=build/ext-check "$0" native
		APP_DIR=testdata/external_app/app APP_NAME=external_check OUT_DIR=build/ext-check "$0" web
		# ... and the page uses the game's own input_map.json, not the Anvil's
		[ "$(readlink build/ext-check/web/external_check/input_map.json)" = "$PWD/testdata/external_app/input_map.json" ] || { echo "the external app's input_map.json was not used" >&2; exit 1; } ;;
	test)
		for pkg in common palette_editor image_editor tileset_editor map_editor terrain_editor sprite_editor character_type_editor character_editor feature_type_editor feature_editor item_type_editor inventory_editor controls_editor world_editor glyph_editor font_editor gamepad_tester launcher anvil_runtime mcp_server; do odin test "$pkg"; done ;;
	install-mcp)
		# A stable "prod" copy of the MCP server, so development can go on (and rebuild build/anvil_mcp)
		# while other sessions use this one. The new file replaces the old by rename, so a running
		# server keeps working until its session ends. ANVIL_PREFIX = the bin folder (default
		# ~/.local/bin); worlds go in ANVIL_WORLDS (default ~/anvil-worlds).
		bin="${ANVIL_PREFIX:-$HOME/.local/bin}"
		worlds="${ANVIL_WORLDS:-$HOME/anvil-worlds}"
		version="r$(git describe --always --dirty 2>/dev/null || echo unknown)" # (the r keeps an all-digit hash from being read as a number)
		mkdir -p build "$bin" "$worlds"
		odin build anvil_mcp -out:build/anvil_mcp-prod -define:ANVIL_VERSION="$version"
		cp build/anvil_mcp-prod "$bin/.anvil_mcp.new" && mv -f "$bin/.anvil_mcp.new" "$bin/anvil_mcp"
		echo "installed $bin/anvil_mcp ($version); worlds in $worlds"
		echo "register it:  claude mcp add --scope user anvil-prod -- $bin/anvil_mcp --dir $worlds" ;;
	mcp)    mkdir -p build && odin build anvil_mcp -out:build/anvil_mcp ;;
	native) mkdir -p "$(dirname "$native_out")" && odin build frontends/sdl2 $coll -out:"$native_out" ;;
	run)    "$0" native "$tool" && "$native_out" "$@" ;;
	web)    build_web ;;
	serve)  build_web && python3 -m http.server -d "$web_out" "${1:-8000}" ;;
	*) echo "unknown target: $target (expected check, test, native, run web or serve)" >&2; exit 2 ;;
esac
