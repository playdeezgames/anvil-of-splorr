# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Status and commands

Platform-independent code plus a native SDL2 frontend; the web frontend is not written yet.

- `common/`: palette model, `Renderer` interface (frontends implement `clear`/`fill_rect`/`present` on a 320x180 logical surface), built-in 3x5 font, and input (`Input_Event` union plus `key_to_action`/`pad_to_action`, the single place keyboard and gamepad bindings live).
- `frontends/sdl2/main.odin`: native frontend (4x integer-scaled logical surface, SDL game controller API, file IO). Palette file is `argv[1]` or `./palette.pal`.
- `palette_editor/`: `Editor` state, `editor_handle_event`, `editor_draw`, and `layout.odin` (rects shared by drawing and mouse hit-testing). File IO is not done here: the editor sets `requests` (Save/Load) and `quit` for the frontend to service, then the frontend calls `editor_set_palette`/`editor_mark_saved`.

A frontend's whole job: convert native events to `Input_Event` (pointer coords in logical pixels), call `editor_handle_event`/`editor_draw`, and service requests. Gamepad quit is the Guide button; Select_R/G/B are keyboard-only (gamepad cycles channels). A test asserts every action has a keyboard binding and every other action a gamepad binding; mouse covers all but quit, which is the window close.

`BACKLOG.md` lists deliberately deferred features (undo, copy/paste, import/export); don't build them unasked.

```bash
./build.sh check   # odin check common and palette_editor
./build.sh test    # odin test both packages (default target)
./build.sh native  # build/palette_editor
./build.sh run [file.pal]
odin test palette_editor -define:ODIN_TEST_NAMES=palette_editor.test_wheel   # single test
```

SDL2 dev headers and libs are installed, so `vendor:sdl2` will link. `build.sh` gains a `web` target when that frontend is written. Unit tests do not cover the SDL2 frontend; to eyeball layout without a window, render `editor_draw` through a software SDL renderer to a BMP.

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
