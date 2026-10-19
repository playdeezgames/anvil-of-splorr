# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Status and commands

A suite of tools sharing two tool-agnostic frontends (native SDL2, web/wasm). Tools so far: `palette_editor` and `gamepad_tester`.

- `common/`: palette model and JSON file format (strict: exactly 16 `{r,g,b}` entries, integers 0..255), `Renderer` interface (frontends implement `clear`/`fill_rect`/`present` on a 320x180 logical surface), built-in 3x5 font, `input.odin` (the eight `Action` commands and the `Input_Event` union), `input_map.odin` (the editable binding table, see below), `gamepad.odin` (`Pad_State` snapshots, standard-layout indices), and `tool.odin` (`Tool`: the proc table a frontend drives; optional file hooks).
- A tool package (`palette_editor/`, `gamepad_tester/`) holds state, event handling and drawing, and exports `tool(&state) -> cm.Tool`. Palette editor: `layout.odin` shares rects between drawing and mouse hit-testing; file IO is a request/response through `Tool.take_save/wants_load/load`, performed by the frontend.
- `apps/<tool>/app/app.odin` picks the tool for a build: frontends `import "app:app"` and the build passes `-collection:app=apps/<tool>`. `apps/<tool>/title.txt` is the web page title. Adding a tool = a package, an `apps/` entry, nothing in the frontends.
- `frontends/sdl2/main.odin`: window, SDL scancode translation, game controller polling into `Pad_State` (controller API only: devices SDL has no standard mapping for are ignored), file IO against `argv[1]` or `Tool.default_file`.
- `frontends/web/`: `web.odin` (`#+build js`; DOM events via `core:sys/wasm/js`, Gamepad API polled in `step`, drawing through `canvas_*` imports), `index.html` (2D-canvas shim; `@TITLE@`/`@TOOL@` filled by `build.sh`; the "Open file" button appears only if the tool has files). Save = localStorage + download; Load = restore localStorage (works from a gamepad).

Input model: tools never see keys or buttons. There are exactly eight commands (up, down, left, right, green, red, blue, yellow) plus mouse events. `input_map.json` (repo root; the web build copies it next to the page, native reads `./input_map.json`) maps gamepad standard-layout button indices (d-pad 12-15, red 0, green 1, yellow 8, blue 9 by default) and KeyboardEvent.code names (arrows, green Space, red Escape, yellow Tab, blue Enter by default) to commands. It is hand-editable: omitted commands keep defaults, `null` unbinds, `_`-prefixed keys are notes, and unknown commands/keys, out-of-range buttons or two commands on one input are errors (frontends report them and fall back to defaults). Key names are the shared vocabulary in `input_map.odin` (`LETTER_CODES`, `DIGIT_CODES`, `NAMED_CODES`); the SDL2 frontend's `key_code` must translate scancodes into those names. `input_map.json` also has a `labels` section: the on-screen name of each command (default = the command name, max 12 chars, `null`/empty = default). Tools get the live map via `Tool.set_input_map` and read labels with `cm.action_label` at draw time, so help text and the mode banner follow the file (the web build applies it a moment after start). New on-screen text that names a command must use `action_label`, never a hardcoded "GREEN". A test requires the committed `input_map.json` to equal `default_input_map()`. Frontends resolve key presses with `action_for_key`, and `tool_update_pads` resolves pad button presses with `action_for_pad_button`; only standard-layout pads produce commands. There is no quit command: native quits by closing the window, web has no quit.

Palette editor modes: Browse (d-pad moves between swatches, green enters Edit) and Edit (left/right = -/+1, up/down = +/-16, green cycles R/G/B, red returns to Browse); blue = save and yellow = load in both; the mouse works in both and switches mode itself. The gamepad tester ignores commands and shows raw `Pad_State` (click to switch pads).

Parity is enforced by tests (`test_every_*_by_each_input`): every swatch, channel, value 0..255, save and load must be reachable with the commands alone (keyboard and gamepad both produce them) and with the mouse alone. Exception: on web, opening a file is a page button (browser file dialog), so command-only users get Save/Load via localStorage instead.

`BACKLOG.md` lists deliberately deferred features; don't build them unasked.

```bash
./build.sh check                 # odin check every package, and both frontends for every tool
./build.sh test                  # odin test every package (default target)
./build.sh run [tool] [file]     # native build + run; tool defaults to palette_editor
./build.sh native|web [tool]     # build/<tool> or build/web/<tool>/
./build.sh serve [tool] [port]   # web + http.server, default :8000
odin test palette_editor -define:ODIN_TEST_NAMES=palette_editor.test_wheel   # single test
```

SDL2 dev headers and libs are installed, so `vendor:sdl2` links. Every `*_test.odin` needs `#+build !js` or the wasm build fails on `core:testing`/`core:os`. Unit tests do not cover the SDL2 or JS glue; to eyeball layout without a window, render a tool's draw through a software SDL renderer to a BMP, or serve the web build and fake `navigator.getGamepads` from the browser console.

## What this is

A suite of tools for making game assets, built to the user's own specs. All tools are written in **Odin** and each runs on two frontends:

- **Native**: SDL2 rendering (Odin's `vendor:sdl2`).
- **Web**: `js_wasm32` build with a browser frontend.

The first tool is a **palette editor**: a 16-entry palette whose entries each hold red, green and blue values in 0..255.

Hard requirement: **every function must be reachable by keyboard, mouse, or gamepad**. When adding a feature, wire up all three input methods.

## Architecture to preserve

Because one tool must run on two very different frontends, keep the tool logic out of the platform code:

- Tool state, input handling and drawing logic live in platform-independent Odin packages. They take abstract input events (keyboard / mouse / gamepad mapped to common actions) and emit draw calls against a small renderer interface (clear, fill rect, text/sprite).
- The SDL2 frontend and the wasm frontend each implement only that renderer interface and translate native events into the common input events. Neither contains tool logic.
- Shared code across tools (renderer interface, input mapping, widgets, palette/file formats) belongs in a common package, not duplicated per tool.

## Odin toolchain notes

Odin is installed at `/home/yermom/.local/bin/odin`. The user's other repos (see `/home/yermom/git/bok-of-splorr/splorr/Tech/Odin wasm recipe.md` and `Gotchas.md`, the shared knowledge vault for their SPLORR!! projects) establish the wasm approach to reuse here:

- Target `js_wasm32` with Odin's own runtime `core/sys/wasm/js/odin.js` (no emscripten): `odin build <pkg> -target:js_wasm32 -out:<dir>/<name>.wasm`, then copy `$(odin root)/core/sys/wasm/js/odin.js` next to it. The page calls `odin.runWasm(...)`.
- The wasm module exports a `step` proc that `odin.js` calls every animation frame; event callbacks must set `context = ctx` (saved in `main`) before using anything context-dependent.
- Draw via a **2D canvas** through `foreign import` procs implemented in the JS page, not WebGL (WebGL was tried and dropped in prior projects).
- The `.wasm` must be served over http (e.g. `python3 -m http.server`), not opened from `file://`.

Read those two vault notes before building the wasm frontend; do not edit the vault from this repo unless asked.
