# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Status and commands

Only the platform-independent `common/` package exists so far (palette model, `Renderer` interface, built-in 3x5 font). No frontends or palette-editor logic yet. `BACKLOG.md` lists deliberately deferred features (undo, copy/paste, import/export); don't build them unasked.

```bash
./build.sh check   # odin check common
./build.sh test    # odin test common (default target)
odin test common -define:ODIN_TEST_NAMES=common.test_bytes_round_trip   # single test
```

SDL2 dev headers and libs are installed, so `vendor:sdl2` will link. `build.sh` gains `native`/`web` targets when those frontends are written.

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
